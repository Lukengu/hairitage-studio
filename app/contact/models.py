from django.db import models
from django.contrib.auth.models import User
from django.db import IntegrityError


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


class Appointment(models.Model):
    id = models.AutoField(primary_key=True)
    full_name = models.CharField(max_length=100)
    email = models.CharField(max_length=100)
    phone = models.CharField(max_length=15)
    service = models.CharField(max_length=100)
    date = models.DateField()
    time = models.TimeField()
    notes = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    reminder_30_sent = models.BooleanField(default=False)
    reminder_5_sent = models.BooleanField(default=False)

    def __str__(self):
        return f'Appointment for {self.full_name} on {self.date} at {self.time}'


class Prospect(models.Model):
    id = models.AutoField(primary_key=True)
    full_name = models.CharField(max_length=100)
    email = models.CharField(max_length=100)
    phone = models.CharField(max_length=15, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['full_name', 'email', 'phone'],
                name='unique_prospect'
            )
        ]

    def save(self, *args, **kwargs):
        # Check if a duplicate already exists
        if Prospect.objects.filter(
                full_name=self.full_name,
                email=self.email,
                phone=self.phone
        ).exists():
            # Skip saving if duplicate found
            return

        try:
            super().save(*args, **kwargs)
        except IntegrityError:
            # In case of race conditions (concurrent saves), skip
            pass

    def __str__(self):
        return self.full_name
