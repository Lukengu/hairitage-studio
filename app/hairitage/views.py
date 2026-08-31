from django.shortcuts import render, redirect
from django.core.paginator import Paginator
from django.contrib import messages
from django import template
from django.core.mail import EmailMessage, get_connection
from django.conf import settings
from django.db.models import Count
from django.template.loader import render_to_string
from django.http import FileResponse, Http404
from django.views.decorators.cache import cache_control
import mimetypes

import product
import configuration
import contact
import blog
import work
from hairitage.storage_backends import MediaGCSStorage

register = template.Library()


@cache_control(max_age=86400, public=True)
def serve_media(request, path):
    if not settings.USE_GCS:
        raise Http404("Media not found")

    storage = MediaGCSStorage()
    if not storage.exists(path):
        raise Http404("Media not found")

    content_type, _ = mimetypes.guess_type(path)
    return FileResponse(storage.open(path), content_type=content_type or "application/octet-stream")


def home_page(request):
    promotion = product.models.Promotion.objects.filter(home_page=True).order_by('-created_at').first()
    posts = blog.models.Post.objects.filter(type='blog').filter(status='PUBLISH').order_by('-date')[:3:1]
    work_categories = work.models.Category.objects.filter(parent_id__isnull=True).order_by('name')

    context = {
        'services': work.models.Service.objects.all().order_by('name'),
        'promotion': promotion,
        'posts': posts,
        'stats': configuration.models.Stats.objects.all(),
        'work_categories': work_categories
    }

    return render(request, "site/home.html", context)