{{- define "oracle-apex.fullname" -}}
{{- .Release.Name }}-{{ .Chart.Name }}
{{- end }}
{{- define "oracle-apex.name" -}}
{{- .Chart.Name -}}
{{- end }}
