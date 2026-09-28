"""sRGB <-> OKLab / OKLCh for the mascot tools (Bjorn Ottosson's OKLab).

Every colour decision in recolor_sheet.py is made here rather than in RGB or
HSV: OKLab lightness tracks what the eye sees, so "keep the shading, change the
paint" becomes "keep the L offsets, move the base colour", and a hue rotation
does not quietly change how light a colour looks.
"""
import numpy as np


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(l):
    l = np.clip(l, 0, 1)
    return np.where(l <= 0.0031308, l * 12.92, 1.055 * l ** (1 / 2.4) - 0.055) * 255.0


M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
               [0.2119034982, 0.6806995451, 0.1073969566],
               [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
               [1.9779984951, -2.4285922050, 0.4505937099],
               [0.0259040371, 0.7827717662, -0.8086757660]])


def srgb_to_oklab(c):
    """sRGB 0..255 (any shape ending in 3) -> OKLab."""
    lms = srgb_to_lin(c) @ M1.T
    return np.cbrt(lms) @ M2.T


def oklab_to_srgb(lab):
    """OKLab -> sRGB 0..255 as floats, clipped to the gamut's 0..1 range."""
    lms_ = lab @ np.linalg.inv(M2).T
    return lin_to_srgb((lms_ ** 3) @ np.linalg.inv(M1).T)


def lch(lab):
    """OKLab -> (L, C, hue in degrees 0..360)."""
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    return L, np.hypot(a, b), np.degrees(np.arctan2(b, a)) % 360


def from_lch(L, C, h):
    hr = np.radians(h)
    return np.stack([L, C * np.cos(hr), C * np.sin(hr)], -1)
