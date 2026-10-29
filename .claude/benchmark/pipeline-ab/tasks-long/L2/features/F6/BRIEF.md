We've started lending back issues of magazines. Add magazines as a material.

Interface (other code will call exactly this):
- New member `Material.MAGAZINE` in `src/lending/models.py`; magazine titles are added with
  `add_title(isbn, name, Material.MAGAZINE, replacement_cost)` as usual.
- Every existing operation keeps its signature and has to handle magazines.
