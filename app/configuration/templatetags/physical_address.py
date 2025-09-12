from django import template
from ..models import Settings
from django.utils.safestring import mark_safe

register = template.Library()


@register.simple_tag
def physical_address():
    setting = Settings.objects.get(pk=1)
    return mark_safe(setting.physical_address)
