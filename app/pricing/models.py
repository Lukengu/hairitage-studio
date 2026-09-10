from django.db import models


class PriceCategory(models.Model):
    """
    A group of priced services shown together on the public price list.
    Example: 'Haircuts & Styling', 'Colour', 'Treatments'.
    """
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=100, unique=True)
    description = models.CharField(max_length=255, blank=True)
    order = models.PositiveIntegerField(default=0, help_text="Lower numbers appear first.")
    created_at = models.DateField(auto_now_add=True)
    updated_at = models.DateField(auto_now=True)

    def __str__(self):
        return self.name

    class Meta:
        verbose_name = "Price Category"
        verbose_name_plural = "Price Categories"
        ordering = ('order', 'name')


class PriceItem(models.Model):
    """
    A single priced service line within a PriceCategory, e.g. 'Full Colour — R650'.
    """
    category = models.ForeignKey(
        PriceCategory,
        on_delete=models.CASCADE,
        related_name="items",
    )
    name = models.CharField(max_length=150)
    description = models.CharField(max_length=255, blank=True)
    price_from = models.DecimalField(max_digits=8, decimal_places=2)
    price_to = models.DecimalField(
        max_digits=8, decimal_places=2, null=True, blank=True,
        help_text="Leave blank for a fixed price, or set a higher amount to show a range (e.g. R350 – R550).",
    )
    duration_minutes = models.PositiveIntegerField(
        null=True, blank=True, help_text="Approximate duration in minutes, shown next to the price.",
    )
    note = models.CharField(
        max_length=150, blank=True, help_text="Optional short note, e.g. 'Long hair may incur an extra charge'.",
    )
    is_popular = models.BooleanField(default=False, help_text="Highlights this item as a popular choice.")
    order = models.PositiveIntegerField(default=0, help_text="Lower numbers appear first within the category.")
    created_at = models.DateField(auto_now_add=True)
    updated_at = models.DateField(auto_now=True)

    def __str__(self):
        return f"{self.name} ({self.category.name})"

    @property
    def is_range(self):
        return self.price_to is not None and self.price_to > self.price_from

    class Meta:
        verbose_name = "Price Item"
        verbose_name_plural = "Price Items"
        ordering = ('order', 'name')
