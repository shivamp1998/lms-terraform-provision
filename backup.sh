echo "Waiting for RDS instance to be available..."
sleep 120  # Adjust the sleep time based on your RDS instance creation time
echo "Restoring the backup..."
DB_ENDPOINT=$(terraform output -raw db_instance_endpoint)
DB_USER="Adil12341"
DB_PASSWORD="Adil1234"
DB_NAME="postgres"
BACKUP_FILE="C:\Users\sarvesh\Desktop\tetr.dump"

mysql -h ${DB_ENDPOINT} -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} < ${BACKUP_FILE}
echo "Backup restored successfully."
EOT

