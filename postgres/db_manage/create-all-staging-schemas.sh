#!/bin/bash

services=(
  "auth_service"
  "profile_service"
  "project_service"
  "mentor_service"
)

for service in "${services[@]}"; do
  echo ""
  echo "======================================================"
  echo "Создание схемы для: $service"
  echo "======================================================"
  ./create-schema.sh "$service" staging
  echo ""
  read -p "Нажмите Enter для продолжения к следующему сервису..."
done

echo ""
echo "✅ Все схемы созданы!"