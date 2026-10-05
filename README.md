# retail-inventory-gitops

Repositorio GitOps de **Reponé**. Contiene los manifiestos de Kubernetes de los microservicios y las `Application` de ArgoCD que los sincronizan con el cluster k3s. El cluster siempre refleja lo que hay en `main`.

## Repositorios relacionados

| Repo | Contenido |
|------|-----------|
| `retail-inventory-app` | Código de los servicios, Dockerfiles y workflows de CI (GitHub Actions) |
| `retail-inventory-terraform` | Infraestructura en AWS (ECR, IAM) |
| `retail-inventory-gitops` | Este repo: estado deseado del cluster |

## Estructura

```
.
├── apps/                      # un directorio por microservicio
│   ├── auth-service/
│   ├── catalog-service/
│   ├── orders-service/
│   └── frontend/
├── infra/                     # recursos compartidos del cluster
│   ├── namespace.yaml
│   └── secrets/               # Sealed Secrets
└── argocd/
    ├── root-app.yaml          # app-of-apps
    └── apps/                  # una Application por servicio
```

Cada directorio de `apps/<servicio>/` contiene `deployment.yaml`, `service.yaml`, `configmap.yaml` y un `kustomization.yaml` que lista los recursos y fija el tag de la imagen. El `frontend` suma además un `ingress.yaml`.

No hay separación por entornos: hay un único cluster y un único entorno. Si más adelante hace falta otro, se puede reorganizar en `base/` + `overlays/`.

## Flujo de despliegue

1. Un push al repo de la app dispara el CI del servicio.
2. El CI construye la imagen y la sube a ECR con el SHA del commit como tag.
3. El CI actualiza `newTag` en `apps/<servicio>/kustomization.yaml` y commitea en este repo.
4. ArgoCD detecta el cambio y sincroniza el cluster.

Nadie aplica manifiestos a mano en el cluster: todo cambio pasa por un commit en este repo.

## Cómo se construye el cluster

1. Instalar ArgoCD en el cluster k3s.
2. Aplicar la app raíz, que crea el resto de las `Application`:

   ```bash
   kubectl apply -f argocd/root-app.yaml
   ```

## Probar un servicio sin ArgoCD

```bash
kubectl apply -k apps/auth-service
kubectl -n repone get pods
```

Para ver los manifiestos renderizados sin aplicarlos:

```bash
kubectl kustomize apps/auth-service
```

## Secrets

Los secrets **nunca** se commitean en texto plano. Se cifran con Sealed Secrets (`kubeseal`) y solo el `SealedSecret` resultante vive en `infra/secrets/`.

## Convenciones

- Las imágenes se referencian por tag inmutable (SHA del commit), nunca `latest`.
- Un servicio por directorio en `apps/` y una `Application` por servicio en `argocd/apps/`.
- Todos los recursos se despliegan en el namespace `repone`.
