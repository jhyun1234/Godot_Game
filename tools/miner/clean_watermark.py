"""Paint over the Gemini sparkle watermark with the background colour. Corner boxes are hand-picked per image."""
from PIL import Image, ImageDraw
jobs = [
    ("Gemini_Generated_Image_4k0umm4k0umm4k0u.png", "miner_front_Tpose_clean.png", (1230, 590, 1350, 710)),
    ("miner_back_Tpose_flipped.png",                 "miner_back_Tpose_clean.png",  (40, 420, 140, 520)),
    ("Gemini_Generated_Image_me5ki0me5ki0me5k.png", "ref_front_timber_clean.png",  (1230, 590, 1350, 710)),
    ("Gemini_Generated_Image_9kc4pj9kc4pj9kc4.png", "ref_back_timber_clean.png",   (1230, 590, 1350, 710)),
    ("head_front.png",                              "head_front_clean.png",        (860, 860, 950, 950)),   # #41 head close-up
    ("hand.png",                                    "hand_clean.png",              (1245, 600, 1345, 685)),   # #42 hand close-up
]
for src, dst, box in jobs:
    im = Image.open(src).convert("RGB")
    bg = im.getpixel((10, 10))
    ImageDraw.Draw(im).rectangle(box, fill=bg)
    im.save(dst); print(dst, im.size, "bg", bg)
