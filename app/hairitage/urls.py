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
from django.urls import path, include
from .views import home_page, about_page, blog_page, contact_page, service_page, work_page, book_appointment
from django.contrib.staticfiles.urls import static, staticfiles_urlpatterns

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', home_page, name="home"),
    path('about.html', about_page, name="about"),
    path('blog.html', blog_page, name="blog"),
    path('blog/', include('blog.urls')),
    path('services.html', service_page, name="services"),
    path('contact.html', contact_page, name="contact"),
    path('work.html', work_page, name="work"),
    path('book_appointment/', book_appointment, name="book_appointment"),
    path('tinymce/', include('tinymce.urls')),
]

urlpatterns += staticfiles_urlpatterns()
