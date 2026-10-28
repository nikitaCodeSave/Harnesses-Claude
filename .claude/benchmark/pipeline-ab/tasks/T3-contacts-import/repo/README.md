# contactbook

Core of the contacts service: the `Contact` entity, field validation, an in-memory
repository, a small use-case layer and CSV export. Persistence adapters and the HTTP
API live in other packages and depend on this one.

## Layout

```
src/contactbook/
  errors.py      domain errors; everything raised on purpose derives from ContactError
  validation.py  normalisers for email, phone, tags and names
  models.py      Contact (immutable; build it from user input with Contact.create)
  repository.py  InMemoryContactRepository, keyed by case-insensitive email
  service.py     ContactBook, use cases on top of a repository
  export.py      CSV export
```

Store only normalised values: go through `validation.py` (or `Contact.create`) rather
than cleaning strings by hand, so that lookups by email keep working.

## Development

Python 3.12, standard library only.

```
python3 -m pytest
```
