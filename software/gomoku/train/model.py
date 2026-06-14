"""
Gomoku CNN Model — small neural network for 15×15 board evaluation.

Architecture:
  Input: 15×15×4 (black, white, current_player, last_move)
  Conv2D 3×3, 4→16, BN, ReLU
  Conv2D 3×3, 16→32, BN, ReLU
  Conv2D 3×3, 32→16, BN, ReLU
  ├─ Policy Head: Conv2D 1×1, 16→1 → Flatten → Softmax (225 moves)
  └─ Value Head:  GlobalAvgPool → FC 16→64 → ReLU → FC 64→1 → Tanh
"""

import torch
import torch.nn as nn
import torch.nn.functional as F


class GomokuCNN(nn.Module):
    """Small CNN for Gomoku board evaluation (policy + value)."""

    def __init__(self, board_size=15, in_channels=4):
        super().__init__()
        self.board_size = board_size

        # Shared convolutional backbone
        self.conv1 = nn.Conv2d(in_channels, 16, kernel_size=3, padding=1)
        self.bn1   = nn.BatchNorm2d(16)

        self.conv2 = nn.Conv2d(16, 32, kernel_size=3, padding=1)
        self.bn2   = nn.BatchNorm2d(32)

        self.conv3 = nn.Conv2d(32, 16, kernel_size=3, padding=1)
        self.bn3   = nn.BatchNorm2d(16)

        # Policy head: 1×1 conv → 225-way softmax
        self.policy_conv = nn.Conv2d(16, 1, kernel_size=1)
        # Output: 225 = 15×15 board positions

        # Value head: global avg pool → FC → Tanh
        self.value_fc1 = nn.Linear(16, 64)
        self.value_fc2 = nn.Linear(64, 1)

    def forward(self, x):
        """
        Args:
            x: tensor [B, 4, 15, 15] — board state
        Returns:
            policy: tensor [B, 225] — move probabilities
            value:  tensor [B, 1]   — position score [-1, 1]
        """
        # Shared backbone
        x = F.relu(self.bn1(self.conv1(x)))
        x = F.relu(self.bn2(self.conv2(x)))
        x = F.relu(self.bn3(self.conv3(x)))

        # Policy head
        p = self.policy_conv(x)           # [B, 1, 15, 15]
        p = p.view(p.size(0), -1)         # [B, 225]
        policy = F.log_softmax(p, dim=1)

        # Value head
        v = x.mean(dim=[2, 3])            # GlobalAvgPool [B, 16]
        v = F.relu(self.value_fc1(v))     # [B, 64]
        v = torch.tanh(self.value_fc2(v)) # [B, 1]

        return policy, v

    def count_parameters(self):
        """Return total number of parameters."""
        return sum(p.numel() for p in self.parameters())


def board_to_tensor(board_state, current_player):
    """
    Convert a 15×15 board state to a 4-channel tensor.

    Args:
        board_state: 15×15 numpy array
            0 = empty, 1 = black, 2 = white
        current_player: 1 (black) or 2 (white)

    Returns:
        tensor of shape [1, 4, 15, 15]
    """
    import numpy as np

    channels = np.zeros((4, 15, 15), dtype=np.float32)

    # Channel 0: black stones
    channels[0] = (board_state == 1).astype(np.float32)
    # Channel 1: white stones
    channels[1] = (board_state == 2).astype(np.float32)
    # Channel 2: current player indicator
    if current_player == 1:
        channels[2] = 1.0  # black to move
    else:
        channels[2] = 0.0  # white to move
    # Channel 3: last move (simplified — mark all opponent stones)
    opponent = 2 if current_player == 1 else 1
    channels[3] = (board_state == opponent).astype(np.float32)

    return torch.from_numpy(channels).unsqueeze(0)


if __name__ == "__main__":
    model = GomokuCNN()
    print(f"GomokuCNN parameters: {model.count_parameters():,}")
    print(f"Model size (int8): ~{model.count_parameters()} bytes")

    # Test forward pass
    x = torch.randn(1, 4, 15, 15)
    policy, value = model(x)
    print(f"Policy shape: {policy.shape}")   # [1, 225]
    print(f"Value shape:  {value.shape}")     # [1, 1]
