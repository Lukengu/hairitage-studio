from django import template
from ..models import Team

register = template.Library()


@register.inclusion_tag('site/tags/teams.html')
def teams():
    return {'teams': Team.objects.all().order_by('name'), }