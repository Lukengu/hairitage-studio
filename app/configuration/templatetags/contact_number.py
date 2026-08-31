from django import template
from ..models import Settings

register = template.Library()


@register.simple_tag
def contact_number():
    setting = Settings.objects.filter(pk=1).first()
    return setting.contact_number if setting else ""
