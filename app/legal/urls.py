from django.urls import path
from .views import terms_of_service, privacy_policy

urlpatterns = [
    path('terms-of-service.html', terms_of_service, name="terms_of_service"),
    path('privacy-policy.html', privacy_policy, name="privacy_policy")
]