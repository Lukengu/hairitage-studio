from django import template
from ..models import Team
from ..models import Service
register = template.Library()


@register.inclusion_tag('site/tags/services.html')
def services():
    return {'services': Service.objects.all()}