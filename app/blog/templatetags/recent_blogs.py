from django import template
from ..models import Post

register = template.Library()


@register.inclusion_tag('site/tags/blogs.html')
def recent_blogs():
    posts = Post.objects.filter(type='blog').filter(status='PUBLISH').order_by('-date')[:2]
    return {'posts': posts}
