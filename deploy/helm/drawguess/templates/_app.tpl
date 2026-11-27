{{/*
  Deployment + Service for one app component (AGENTS.md rule 8).
  Call with (dict "ctx" $ "key" "gameServer" "name" "game-server").
*/}}
{{- define "drawguess.app" -}}
{{- $ctx := .ctx -}}
{{- $c := index $ctx.Values .key -}}
{{- $component := .name -}}
{{- $name := printf "%s-%s" (include "drawguess.fullname" $ctx) $component -}}
{{- $tag := required "image.tag is required: `make deploy` sets it to the git SHA used by `make build`" $ctx.Values.image.tag -}}
{{- if $c.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: {{ $name }}
  labels:
    {{- include "drawguess.labels" (dict "ctx" $ctx "component" $component) | nindent 4 }}
  {{- if $ctx.Values.ingress.enabled }}
  annotations:
    # D15: Traefik gives up on a dead pod after ingress.dialTimeout and retries another one.
    traefik.ingress.kubernetes.io/service.serverstransport: {{ printf "%s-%s-transport@kubernetescrd" $ctx.Release.Namespace (include "drawguess.fullname" $ctx) }}
  {{- end }}
spec:
  selector:
    {{- include "drawguess.selectorLabels" (dict "ctx" $ctx "component" $component) | nindent 4 }}
  ports:
    - {name: http, port: 80, targetPort: http}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $name }}
  labels:
    {{- include "drawguess.labels" (dict "ctx" $ctx "component" $component) | nindent 4 }}
spec:
  replicas: {{ $c.replicas }}
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    # Never below the desired count during an update (demo 4); one extra pod at a time.
    rollingUpdate: {maxUnavailable: 0, maxSurge: 1}
  selector:
    matchLabels:
      {{- include "drawguess.selectorLabels" (dict "ctx" $ctx "component" $component) | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "drawguess.labels" (dict "ctx" $ctx "component" $component) | nindent 8 }}
        app.kubernetes.io/version: {{ $tag | quote }}
      annotations:
        # Roll the pods when the shared configuration changes.
        checksum/config: {{ include (print $ctx.Template.BasePath "/configmap.yaml") $ctx | sha256sum | trunc 16 }}
    spec:
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: {{ $ctx.Values.app.terminationGracePeriodSeconds }}
      securityContext:
        runAsNonRoot: true
        runAsUser: {{ $ctx.Values.app.runAsUser }}
        runAsGroup: {{ $ctx.Values.app.runAsGroup }}
        seccompProfile: {type: RuntimeDefault}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          # D1: a cordoned node's zone must not count, or evicted pods stay Pending on drain.
          nodeTaintsPolicy: Honor
          # Spread each ReplicaSet revision on its own: counting the old pods during a rolling
          # update left 2 of 3 game-servers on one node (seen on k3d), so one node failure
          # took out two thirds of them.
          matchLabelKeys: [pod-template-hash]
          labelSelector:
            matchLabels:
              {{- include "drawguess.selectorLabels" (dict "ctx" $ctx "component" $component) | nindent 14 }}
      tolerations:
        # D9: leave a dead node after this many seconds instead of the default 300.
        - {key: node.kubernetes.io/not-ready, operator: Exists, effect: NoExecute, tolerationSeconds: {{ $ctx.Values.app.nodeFailureTolerationSeconds }}}
        - {key: node.kubernetes.io/unreachable, operator: Exists, effect: NoExecute, tolerationSeconds: {{ $ctx.Values.app.nodeFailureTolerationSeconds }}}
      containers:
        - name: {{ $component }}
          image: "{{ $c.image.repository }}:{{ $tag }}"
          imagePullPolicy: {{ $ctx.Values.image.pullPolicy }}
          ports:
            - {name: http, containerPort: {{ $c.port }}}
          envFrom:
            - configMapRef:
                name: {{ include "drawguess.fullname" $ctx }}-config
          env:
            - {name: PORT, value: {{ $c.port | quote }}}
            - {name: VERSION, value: {{ $tag | quote }}}
            - name: POD_NAME
              valueFrom: {fieldRef: {fieldPath: metadata.name}}
            {{- range $k, $v := $c.env }}
            - {name: {{ $k }}, value: {{ $v | quote }}}
            {{- end }}
            {{- if and $c.needsRedis $ctx.Values.redis.enabled }}
            - {name: REDIS_URL, value: "redis://{{ include "drawguess.redis.fullname" $ctx }}:6379"}
            {{- end }}
            {{- if and $c.needsPostgres $ctx.Values.postgres.enabled }}
            - {name: PGHOST, value: {{ include "drawguess.postgres.fullname" $ctx | quote }}}
            - {name: PGPORT, value: "5432"}
            - {name: PGDATABASE, value: {{ $ctx.Values.postgres.auth.database | quote }}}
            - {name: PGUSER, value: {{ $ctx.Values.postgres.auth.username | quote }}}
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "drawguess.postgres.secretName" $ctx }}
                  key: password
            {{- end }}
          securityContext:
            {{- include "drawguess.containerSecurityContext" $ctx | nindent 12 }}
          resources:
            {{- toYaml $c.resources | nindent 12 }}
          startupProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 1
            failureThreshold: 60
          readinessProbe:
            httpGet: {path: /readyz, port: http}
            periodSeconds: 2
            timeoutSeconds: 2
            failureThreshold: 2
          livenessProbe:
            # Lesson from the stub (P0-5): tolerant enough that load alone never restarts a pod.
            httpGet: {path: /healthz, port: http}
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          lifecycle:
            preStop:
              # Keep serving while Traefik drops this pod from its endpoints (a few seconds);
              # only then does SIGTERM arrive. Without it, new WebSocket upgrades still reached
              # a stopping pod during rolling updates and got 503 (seen on k3d).
              sleep: {seconds: {{ $ctx.Values.app.preStopSleepSeconds }}}
          volumeMounts:
            - {name: tmp, mountPath: /tmp}
      volumes:
        - {name: tmp, emptyDir: {}}
{{- end }}
{{- end -}}
