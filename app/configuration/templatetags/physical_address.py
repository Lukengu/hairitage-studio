from django import template
from ..models import Settings
from django.utils.safestring import mark_safe

register = template.Library()


@register.simple_tag
def physical_address():
    setting = Settings.objects.filter(pk=1).first()
    if not setting or not setting.physical_address:
        return ""
    return mark_safe(setting.physical_address)
