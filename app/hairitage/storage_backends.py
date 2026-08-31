from django.conf import settings
from storages.backends.gcloud import GoogleCloudStorage


class StaticGCSStorage(GoogleCloudStorage):
    location = "static"
    default_acl = None
    file_overwrite = True


class MediaGCSStorage(GoogleCloudStorage):
    location = "media"
    default_acl = None
    file_overwrite = False

    def url(self, name):
        if settings.GCS_PUBLIC_BUCKET:
            return super().url(name)
        return f"{settings.MEDIA_URL}{name}"
