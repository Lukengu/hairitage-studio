from django import template

from ..models import Settings

register = template.Library()

# Common currency symbols, keyed by ISO 4217 code. Falls back to the code itself
# (e.g. "AED") when a symbol isn't listed here.
CURRENCY_SYMBOLS = {
    'ZAR': 'R',
    'USD': '$',
    'EUR': '€',
    'GBP': '£',
}


@register.simple_tag
def currency_symbol():
    setting = Settings.objects.filter(pk=1).first()
    code = ((setting.currency_code if setting else '') or 'ZAR').upper()
    return CURRENCY_SYMBOLS.get(code, code)
