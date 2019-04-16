apiVersion: v1 
metadata:
  name: {{.Values.key}}
data:
  {{.Values.name}}: {{.Values.value}}
kind: ConfigMap
