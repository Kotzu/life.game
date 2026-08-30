# Default Clothing Coverage Report

Generated: 2026-08-30T00:23:19.236983+00:00 · game build 3258 · manifest v1

## Coverage: **100.0%** (189/189 garment drawables render skin-free)

| Gender | Total | Supported | Pending conversion | Manual review | Incompatible |
|---|---|---|---|---|---|
| male | 97 | 97 | 0 | 0 | 0 |
| female | 92 | 92 | 0 | 0 | 0 |

Body set present per gender (component IDs): male: head, hair, uppr, lowr, hand, teef; female: head, hair, uppr, lowr, hand, feet, teef

## Interpretation rules (acceptance §6)
- A garment counts as *supported* only when `skin_free` (verified) or `converted`.
- `pending`, `pending_review`, `incompatible` garments are refused in game with an
  explicit incompatible state — they never render human skin.
- "All default clothing supported" may only be claimed when Supported == Total
  for both genders on the server's game build.
