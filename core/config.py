PROFILES = {
    "conversational": {
        "name": "conversational",
        "boundary_threshold": 0.55,
        "max_chars": 45,
        "max_duration": 8.0,
        "weak_conj_boost": 1.3,
        "gap_break": 0.8,
    },
    "lecturing": {
        "name": "lecturing",
        "boundary_threshold": 0.70,
        "max_chars": 70,
        "max_duration": 10.0,
        "weak_conj_boost": 0.8,
        "gap_break": 1.3,
    },
    "technical": {
        "name": "technical",
        "boundary_threshold": 0.62,
        "max_chars": 55,
        "max_duration": 9.0,
        "weak_conj_boost": 1.0,
        "gap_break": 1.0,
    },
}

DEFAULT_PROFILE = "conversational"
