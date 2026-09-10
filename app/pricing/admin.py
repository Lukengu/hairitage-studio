from django.contrib import admin

from .models import PriceCategory, PriceItem


class PriceItemInline(admin.TabularInline):
    model = PriceItem
    extra = 1
    fields = ('name', 'description', 'price_from', 'price_to', 'duration_minutes', 'is_popular', 'order')


@admin.register(PriceCategory)
class PriceCategoryAdmin(admin.ModelAdmin):
    list_display = ('name', 'description', 'order', 'item_count')
    search_fields = ('name', 'description')
    ordering = ('order', 'name')
    inlines = [PriceItemInline]

    @admin.display(description="Items")
    def item_count(self, obj):
        return obj.items.count()


@admin.register(PriceItem)
class PriceItemAdmin(admin.ModelAdmin):
    list_display = ('name', 'category', 'price_from', 'price_to', 'duration_minutes', 'is_popular', 'order')
    list_filter = ('category', 'is_popular')
    search_fields = ('name', 'description')
    ordering = ('category__order', 'order', 'name')
