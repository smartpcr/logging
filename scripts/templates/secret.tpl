apiVersion: v1
data:
  {{ .Values.name }}: {{ .Values.value }}
kind: Secret
metadata:
  name: {{ .Values.key }}
type: Opaque
