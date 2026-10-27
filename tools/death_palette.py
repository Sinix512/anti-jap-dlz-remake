"""4240B9/421DDB indexed death dissolve. No original executable is run.

The third argument is an early-match squared-distance threshold, NOT a nearest
color tolerance to apply after argmin. See research_death_palette_contract.
"""
from pathlib import Path


def highlight_lut(palette_bytes: bytes) -> bytes:
    """424B31/421F68/421D10: half RGB, weighted distance, first tie.

    Deliberately NOT the 421DDB early-threshold lookup used by death mixing.
    """
    colors = [tuple(palette_bytes[i:i+3]) for i in range(0, 768, 3)]
    result = []
    for color in colors:
        target = [c * 50 // 100 for c in color]
        distances = [(30*(r-target[0])**2 + 59*(g-target[1])**2 +
                      11*(b-target[2])**2) // 100 for r, g, b in colors]
        result.append(min(range(256), key=distances.__getitem__))
    return bytes(result)


def lookup(color, palette, threshold=1152):
    best_distance, best = 20000, None
    for i, entry in enumerate(palette):
        distance = sum((int(a) - int(b)) ** 2 for a, b in zip(color, entry))
        if distance < threshold:
            return i
        if distance < best_distance:
            best_distance, best = distance, i
    # The original reads an uninitialized stack byte in this unreachable-for-
    # shipped-palette domain. Refuse generation instead of fabricating a color.
    if best is None:
        raise ValueError("421DDB undefined original palette boundary")
    return best


def generate(palette_bytes: bytes, output: Path) -> None:
    import numpy as np
    from PIL import Image
    palette = np.frombuffer(palette_bytes, dtype=np.uint8).reshape(256, 3).astype(np.int32)
    old = np.repeat(np.arange(256), 256)
    new = np.tile(np.arange(256), 256)
    target = np.where((new == 255)[:, None], palette[old], palette[new])
    frames = []
    for weight in range(0, 257, 8):
        colors = (palette[old] * (256 - weight) + target * weight) >> 8
        result = np.zeros(65536, dtype=np.uint8)
        best = np.full(65536, 20000, dtype=np.int32)
        settled = old == new
        result[settled] = old[settled]
        for i, entry in enumerate(palette):
            distance = np.sum((colors - entry) ** 2, axis=1)
            early = (~settled) & (distance < 1152)
            closer = (~settled) & (distance < best)
            result[closer] = i
            best[closer] = distance[closer]
            result[early] = i
            settled |= early
        if np.any((~settled) & (best == 20000)):
            raise ValueError("shipped palette reaches undefined 421DDB boundary")
        frames.append(result.reshape(256, 256))
    output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.concatenate(frames), "L").save(output)
