"""Domain errors raised by the billing package."""


class BillingError(Exception):
    """Base class for every error the billing domain raises on purpose."""


class InvalidPlan(BillingError):
    """A plan definition is malformed (bad code, negative or sub-cent price)."""


class PlanNotFound(BillingError):
    """No plan with the requested code exists."""


class PlanNotAvailable(BillingError):
    """The plan exists but is retired and can no longer be sold."""


class SubscriptionNotFound(BillingError):
    """No subscription with the requested id exists."""


class SubscriptionNotActive(BillingError):
    """The operation needs a live subscription, but this one is canceled."""


class InvoiceError(BillingError):
    """An invoice or line item is malformed."""
