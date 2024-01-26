from django.urls import path, include
from .views import settings_page

urlpatterns = [
    path('settings/', settings_page, name='settings'),
]
