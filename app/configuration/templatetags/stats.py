from django import template
from ..models import Stats
register = template.Library()


@register.inclusion_tag('site/tags/stats.html', takes_context=True)
def stats(context):
    site_stats = Stats.objects.all()
    return {
        'stats': site_stats
    }