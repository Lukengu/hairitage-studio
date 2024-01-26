from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ('blog', '0003_post_comment_count'),
    ]

    trigger_sql = """
      CREATE OR REPLACE FUNCTION update_comment ()
      RETURNS TRIGGER AS $$
      DECLARE
        ct INT := 0;
      BEGIN
          SELECT COUNT(*) INTO ct FROM blog_comment WHERE post_id = NEW.post_id;
          UPDATE blog_post SET comment_count = ct WHERE post_id = NEW.post_id;
          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trig_comment_count
      AFTER INSERT ON blog_comment
      FOR EACH ROW
      EXECUTE PROCEDURE update_comment();
    """

    reverse_sql = """
      DROP TRIGGER IF EXISTS trig_comment_count ON blog_comment;
      DROP FUNCTION IF EXISTS update_comment();
    """

    operations = [
        migrations.RunSQL(
            sql=trigger_sql,
            reverse_sql=reverse_sql
        )
    ]
