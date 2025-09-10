from django.urls import path
from .views import terms_of_service, privacy_policy

urlpatterns = [
    path('terms_of_services.html', terms_of_service, name="blog_details"),
    path('privacy_policy.html', privacy_policy, name="privacy_policy")
]