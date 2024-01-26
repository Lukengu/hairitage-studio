from django import template

register = template.Library()


@register.inclusion_tag('site/tags/breadcrumb.html', takes_context=True)
def breadcrumb(context):
    request = context["request"]
    page = {}
    link = ''

    if request.path == '/':
        page[0] = 'home'
    else:
        page_string = request.path.replace('.html', '')
        page = page_string.split("/")

    return {'page': page, 'link': link}
