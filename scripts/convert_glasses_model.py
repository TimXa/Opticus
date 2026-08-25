#!/usr/bin/env python3
"""Convert a mantasu/glasses-detector eyeglasses model to Core ML.

Conversion dependencies and downloaded weights are build-time only. Opticus
ships the compiled Core ML model and does not embed Python or PyTorch.
"""

from pathlib import Path
import sys

import coremltools as ct
import torch
from torch import nn
from torchvision.models import shufflenet_v2_x1_0


class TinyBinaryClassifier(nn.Module):
    def __init__(self):
        super().__init__()
        channels = (3, 5, 10, 15, 20, 25, 80)
        blocks = []
        for source, target in zip(channels, channels[1:]):
            blocks.append(
                nn.Sequential(
                    nn.Conv2d(source, target, 3, 1, "valid", bias=False),
                    nn.ReLU(),
                    nn.BatchNorm2d(target),
                    nn.MaxPool2d(2, 2),
                )
            )
        self.features = nn.Sequential(*blocks, nn.AdaptiveAvgPool2d(1), nn.Flatten())
        self.fc = nn.Linear(80, 1)

    def forward(self, value):
        return self.fc(self.features(value))


class EyeglassesProbability(nn.Module):
    def __init__(self, classifier):
        super().__init__()
        self.classifier = classifier
        self.register_buffer("mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))

    def forward(self, image):
        normalized = (image - self.mean) / self.std
        return torch.sigmoid(self.classifier(normalized)).squeeze(1)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: convert_glasses_model.py WEIGHTS.pth OUTPUT.mlpackage")
    weights_path, output_path = map(Path, sys.argv[1:])
    if "shufflenet" in weights_path.name:
        classifier = shufflenet_v2_x1_0(weights=None)
        classifier.fc = nn.Linear(classifier.fc.in_features, 1)
    else:
        classifier = TinyBinaryClassifier()
    classifier.eval()
    classifier.load_state_dict(torch.load(weights_path, map_location="cpu", weights_only=True))
    wrapped = EyeglassesProbability(classifier).eval()
    traced = torch.jit.trace(wrapped, torch.rand(1, 3, 256, 256))
    model = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS14,
        inputs=[ct.ImageType(name="face", shape=(1, 3, 256, 256), scale=1 / 255, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="eyeglassesProbability")],
    )
    model.author = "Mantas Birškus; Core ML conversion for Opticus"
    model.license = "MIT"
    model.short_description = "Any-glasses classifier from mantasu/glasses-detector."
    model.save(output_path)


if __name__ == "__main__":
    main()
