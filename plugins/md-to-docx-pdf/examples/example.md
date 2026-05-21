# Example Report

## 1. Introduction

This document is rendered by `md_to_docx_pdf.py`. The first H1 above is consumed
by the **title page**, so body content starts at the first H2.

It supports **bold**, *italic*, ***bold-italic***, inline `code`, and escaped
literals like A\*STAR that must not trigger italics.

## 2. A table

Column widths are computed from content so the table stays compact:

| Field | Type | Notes |
|---|---|---|
| `id` | integer | Primary key, auto-increment |
| `name` | string | Display name shown to the user |
| `created_at` | timestamp | Set once at insert time; never updated afterwards |

## 3. Lists

- First bullet
- Second bullet
  - Nested bullet

1. Step one
2. Step two

- [x] Done item
- [ ] Pending item

## 4. Code block

```
def hello(name):
    return f"hi {name}"
```

## 5. Closing

A horizontal rule follows.

---

End of example.
