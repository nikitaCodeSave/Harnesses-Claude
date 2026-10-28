from contactbook.models import Contact


def test_create_normalises_every_field():
    contact = Contact.create(
        name=" Ann  Lee ",
        email="Ann@Example.com",
        phone="+1 555 123 4567",
        tags=["VIP", "vip", "Key Account"],
    )
    assert contact == Contact(
        name="Ann Lee",
        email="ann@example.com",
        phone="+15551234567",
        tags=frozenset({"vip", "key-account"}),
    )


def test_blank_phone_means_no_phone():
    assert Contact.create(name="Ann", email="ann@example.com", phone="  ").phone is None


def test_with_tags_adds_to_existing_tags():
    contact = Contact.create(name="Ann", email="ann@example.com", tags=["vip"])
    assert contact.with_tags("Partner").tags == {"vip", "partner"}


def test_without_tags_removes_only_given_tags():
    contact = Contact.create(name="Ann", email="ann@example.com", tags=["vip", "partner"])
    assert contact.without_tags("VIP").tags == {"partner"}
