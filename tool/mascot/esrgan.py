"""Real-ESRGAN 4x inference for upscale_poses.py, without the realesrgan and
basicsr packages (their pins lag current torch and torchvision).

The network is RRDBNet as published in xinntao/Real-ESRGAN (BSD-3-Clause):
the anime model is the 6-block variant. The weights come from that project's
official GitHub release, are cached OUTSIDE the repo, are checked against the
SHA-256 of the file this was built and verified with on 2026-09-27, and are
loaded with torch.load(weights_only=True), so the file is read as tensors only
and can never run code.
"""
import hashlib
import os
import pathlib
import urllib.request

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

WEIGHTS_URL = ("https://github.com/xinntao/Real-ESRGAN/releases/download/"
               "v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth")
WEIGHTS_SHA256 = "f872d837d3c90ed2e05227bed711af5671a6fd1c9f7d7e91c911a61f155e99da"
CACHE = pathlib.Path(os.environ.get("XDG_CACHE_HOME", pathlib.Path.home() / ".cache")) / "growdaily"
NUM_BLOCK = 6


class RDB(nn.Module):
    def __init__(self, nf=64, gc=32):
        super().__init__()
        self.conv1 = nn.Conv2d(nf, gc, 3, 1, 1)
        self.conv2 = nn.Conv2d(nf + gc, gc, 3, 1, 1)
        self.conv3 = nn.Conv2d(nf + 2 * gc, gc, 3, 1, 1)
        self.conv4 = nn.Conv2d(nf + 3 * gc, gc, 3, 1, 1)
        self.conv5 = nn.Conv2d(nf + 4 * gc, nf, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(0.2, True)

    def forward(self, x):
        x1 = self.lrelu(self.conv1(x))
        x2 = self.lrelu(self.conv2(torch.cat((x, x1), 1)))
        x3 = self.lrelu(self.conv3(torch.cat((x, x1, x2), 1)))
        x4 = self.lrelu(self.conv4(torch.cat((x, x1, x2, x3), 1)))
        return self.conv5(torch.cat((x, x1, x2, x3, x4), 1)) * 0.2 + x


class RRDB(nn.Module):
    def __init__(self, nf, gc=32):
        super().__init__()
        self.rdb1, self.rdb2, self.rdb3 = RDB(nf, gc), RDB(nf, gc), RDB(nf, gc)

    def forward(self, x):
        return self.rdb3(self.rdb2(self.rdb1(x))) * 0.2 + x


class RRDBNet(nn.Module):
    def __init__(self, num_block, nf=64, gc=32):
        super().__init__()
        self.conv_first = nn.Conv2d(3, nf, 3, 1, 1)
        self.body = nn.Sequential(*[RRDB(nf, gc) for _ in range(num_block)])
        self.conv_body = nn.Conv2d(nf, nf, 3, 1, 1)
        self.conv_up1 = nn.Conv2d(nf, nf, 3, 1, 1)
        self.conv_up2 = nn.Conv2d(nf, nf, 3, 1, 1)
        self.conv_hr = nn.Conv2d(nf, nf, 3, 1, 1)
        self.conv_last = nn.Conv2d(nf, 3, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(0.2, True)

    def forward(self, x):
        feat = self.conv_first(x)
        feat = feat + self.conv_body(self.body(feat))
        feat = self.lrelu(self.conv_up1(F.interpolate(feat, scale_factor=2, mode='nearest')))
        feat = self.lrelu(self.conv_up2(F.interpolate(feat, scale_factor=2, mode='nearest')))
        return self.conv_last(self.lrelu(self.conv_hr(feat)))


def _sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def weights(path=None):
    """The verified weights file, downloading it into the cache on first use."""
    path = pathlib.Path(path) if path else CACHE / "RealESRGAN_x4plus_anime_6B.pth"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix('.part')
        print(f"downloading {WEIGHTS_URL} (17.9 MB) to {path}")
        urllib.request.urlretrieve(WEIGHTS_URL, tmp)
        tmp.replace(path)
    digest = _sha256(path)
    if digest != WEIGHTS_SHA256:
        raise SystemExit(f"{path} has SHA-256 {digest}, expected {WEIGHTS_SHA256}; delete it and re-run")
    return path


def load(path=None):
    sd = torch.load(weights(path), map_location='cpu', weights_only=True)
    sd = sd.get('params_ema', sd.get('params', sd))
    net = RRDBNet(NUM_BLOCK)
    net.load_state_dict(sd, strict=True)
    net.eval()
    dev = torch.device('mps' if torch.backends.mps.is_available() else 'cpu')
    return net.to(dev), dev


@torch.no_grad()
def upscale(net, dev, img, pad=16):
    """img: H x W x 3 float32 in 0..1 -> 4H x 4W x 3. Edge-replicate padding keeps
    the model from inventing a border."""
    t = torch.from_numpy(np.ascontiguousarray(img.transpose(2, 0, 1))).float()[None]
    t = F.pad(t, (pad, pad, pad, pad), mode='replicate').to(dev)
    out = net(t).clamp_(0, 1)[0].cpu().numpy().transpose(1, 2, 0)
    return out[4 * pad:-4 * pad, 4 * pad:-4 * pad]
