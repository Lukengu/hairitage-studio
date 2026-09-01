from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('contact', '0004_prospect'),
    ]

    operations = [
        migrations.AddField(
            model_name='appointment',
            name='reminder_30_sent',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='appointment',
            name='reminder_5_sent',
            field=models.BooleanField(default=False),
        ),
    ]
