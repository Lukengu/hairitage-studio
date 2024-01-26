from django import template
from ..models import Settings

register = template.Library()


@register.simple_tag
def contact_number():
    setting = Settings.objects.get(pk=1)
    return setting.contact_number
