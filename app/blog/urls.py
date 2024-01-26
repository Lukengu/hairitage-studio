from django.urls import path
from .views import blog_details

urlpatterns = [
    path('details.html', blog_details, name="blog_details")
]