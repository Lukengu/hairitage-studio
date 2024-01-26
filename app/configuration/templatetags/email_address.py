from django import template
from ..models import Settings

register = template.Library()


@register.simple_tag
def email_address():
    setting = Settings.objects.get(pk=1)
    return setting.email_address
