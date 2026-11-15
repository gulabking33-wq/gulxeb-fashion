# Gulxeb Fashion Industries — online store

Live site: https://gulabking33-wq.github.io/gulxeb-fashion/

A single-page fashion storefront (men's and women's suits, blazers, coat-pant) that takes orders on WhatsApp.

## How ordering works
1. Customer browses, picks size and quantity, adds to bag.
2. At checkout they enter name, mobile, email and address, and choose UPI or Cash on Delivery.
3. "Place Order on WhatsApp" opens WhatsApp with the full order (items, sizes, total, customer details) addressed to the store number. The customer taps send.
4. You confirm the order on WhatsApp and share the UPI payment link.

## Editing the shop
Everything is in `index.html`. Edit on GitHub (pencil icon) and commit; the site updates in about a minute.
- **WhatsApp number:** the `CONFIG` block near the top of the `<script>` — `whatsappNumber: "916204524008"` (country code, digits only).
- **Logo:** upload an image named `logo.png` to this repository.
- **Products and prices:** the `PRODUCTS` list just below `CONFIG`.
