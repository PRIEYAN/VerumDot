"""The error type these tools report to their caller."""


class RiceError(Exception):
    """An error that is meaningful to the user.

    Everything raised deliberately is a RiceError, which is what lets the
    entry point draw a clean line between "this went wrong and here is why"
    and a genuine bug. An unexpected exception must not be flattened into
    the same `{"error": ...}` shape as an expected one — that is how a
    traceback gets hidden behind a tidy message and never investigated.
    """
