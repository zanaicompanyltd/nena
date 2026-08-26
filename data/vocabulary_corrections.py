CORRECTED_VOCABULARY_ENTRIES = [
    {
        # S0057_Babu.mp4 — RE-CHECKED with full frame sequence
        # Right hand starts near chest/waist with fingers moving,
        # then touches/pats the top of the head twice,
        # then lowers into a loose fist near the hip while the body
        # bends slightly forward
        "id": "babu",
        "swahili_text": "Babu",
        "description": "A person touching the top of the head with the right hand and patting it, then lowering the hand into a loose fist near the hip while bending the body slightly forward, meaning grandfather",
        "reference_img": None,
    },
    {
        # S0058_Mke.mp4 — RE-CHECKED with full frame sequence
        # Right flat hand starts near the chin/mouth area then sweeps
        # downward and outward across the chest in one continuous
        # smooth diagonal motion, ending with the hand extended out
        # to the side at chest height
        "id": "mke",
        "swahili_text": "Mke",
        "description": "A person starting with the right flat hand near the chin then sweeping it downward and outward across the chest in one smooth diagonal motion, ending with the hand extended to the side at chest height, meaning wife",
        "reference_img": None,
    },
    {
        # S0059_Mume.mp4 — RE-CHECKED with full frame sequence
        # Right hand starts open at chest level, gesturing while speaking,
        # then the fingers bunch together and the hand rises to touch
        # or tap near the chin/mouth area, held briefly at the chin
        "id": "mume",
        "swahili_text": "Mume",
        "description": "A person starting with the right hand open at chest level then bunching the fingers together and raising the hand to tap or touch near the chin, holding it briefly at the chin, meaning husband",
        "reference_img": None,
    },
    {
        # S0060_Mtoto.mp4 — RE-CHECKED with full frame sequence
        # Right hand held at chest height with fingers loosely open,
        # rubbing or rolling the fingers and thumb together repeatedly
        # (a fidgeting/small motion), hand gradually lowers while
        # head tilts down to look at the hand
        "id": "mtoto",
        "swahili_text": "Mtoto",
        "description": "A person holding the right hand at chest height with fingers loosely open, rubbing the fingers and thumb together in a small repeated motion while the hand gradually lowers and the head tilts down to look at it, meaning child",
        "reference_img": None,
    },
    {
        # S0068_Mkuu.mp4 — RE-CHECKED with full frame sequence
        # Starts neutral, then right hand lowers and opens beside the hip,
        # then both hands rise together to shoulder height with index
        # fingers pointing straight up side by side, then both hands
        # open and lower back down to waist level with palms facing
        # slightly outward
        "id": "mkuu",
        "swahili_text": "Mkuu",
        "description": "A person raising both hands to shoulder height with the index fingers pointing straight up side by side, then opening both hands and lowering them back down to waist level with palms facing slightly outward, meaning boss or leader",
        "reference_img": None,
    },
]

print("Corrected entries:")
for e in CORRECTED_VOCABULARY_ENTRIES:
    print(f"  {e['id']:<10} → {e['swahili_text']}")
