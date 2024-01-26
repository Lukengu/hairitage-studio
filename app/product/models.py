from django.db import models


class Promotion(models.Model):
    id = models.AutoField(primary_key=True)
    rate = models.IntegerField()
    title = models.CharField(max_length=100)
    banner = models.ImageField(upload_to='promotions/')
    description = models.TextField()
    home_page = models.BooleanField(default=False)
    created_at = models.DateField(auto_now_add=True)

    def __str__(self):
        return self.title
