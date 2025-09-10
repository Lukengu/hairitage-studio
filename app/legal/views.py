from django.shortcuts import render
from .models import TermsOfService, PrivacyPolicy


def terms_of_service(request):
    terms = TermsOfService.objects.first()
    return render(request, 'site/legal/terms_of_service.html', {'terms_of_service': terms})


def privacy_policy(request):
    privacy = PrivacyPolicy.objects.first()
    return render(request, 'site/legal/privacy_policy.html', {'privacy_policy': privacy})