from django.db import models
from django.contrib.auth.models import User


class Message(models.Model):
    id = models.AutoField(primary_key=True)
    full_name = models.CharField(max_length=100)
    email = models.CharField(max_length=100)
    subject = models.CharField(max_length=100)
    message_text = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.subject


class Reply(models.Model):
    id = models.AutoField(primary_key=True)
    message_id = models.ForeignKey(Message, on_delete=models.CASCADE)
    user_id = models.ForeignKey(User, on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)
    message_text = models.TextField()
    subject = models.CharField(max_length=100)

    def __str__(self):
        return self.subject

    class Meta:
        verbose_name_plural = "replies"
