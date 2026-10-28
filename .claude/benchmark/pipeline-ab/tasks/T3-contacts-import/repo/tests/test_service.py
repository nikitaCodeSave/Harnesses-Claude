from contactbook.service import ContactBook


def test_add_then_tag():
    book = ContactBook()
    book.add("Ann Lee", "ann@example.com", tags=["vip"])
    assert book.tag("ann@example.com", "partner").tags == {"vip", "partner"}


def test_set_phone_none_clears_phone():
    book = ContactBook()
    book.add("Ann Lee", "ann@example.com", phone="+15551234567")
    assert book.set_phone("ann@example.com", None).phone is None


def test_search_matches_name_and_email():
    book = ContactBook()
    book.add("Ann Lee", "ann@example.com")
    book.add("Bob Stone", "bob@leeway.io")
    assert [c.email for c in book.search("LEE")] == ["ann@example.com", "bob@leeway.io"]
