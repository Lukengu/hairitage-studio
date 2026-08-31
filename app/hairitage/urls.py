"""
URL configuration for hairitage project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include, re_path
from .views import home_page, serve_media

from django.contrib.staticfiles.urls import static, staticfiles_urlpatterns
from blog import views as blog_views
from contact import views as contact_views
from product import views as product_views
from work import views as work_views

urlpatterns = [
    path('admin/', admin.site.urls),
    re_path(r'^media/(?P<path>.*)$', serve_media, name='serve_media'),
    path('', home_page, name="home"),
    path('about.html', blog_views.about_page, name="about"),
    path('blog.html', blog_views.blog_page, name="blog"),
    path('blog/', include('blog.urls')),
    path('services.html', product_views.service_page, name="services"),
    path('contact.html', contact_views.contact_page, name="contact"),
    path('book.html', contact_views.booking_page, name="booking"),
    path('work.html', work_views.work_page, name="work"),
    path('book_appointment/', contact_views.book_appointment, name="book_appointment"),
    path('tinymce/', include('tinymce.urls')),
    path('legal/', include('legal.urls')),
    path('logs/', include('log.urls')),
]

urlpatterns += staticfiles_urlpatterns()
