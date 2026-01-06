# Get the IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Sign up
curl -X POST http://${INGRESS_IP}/signup \
  -H "Content-Type: application/json" \
  -d '{"username":"demo","email":"demo@example.com","password":"Demo123!"}'

# Login (save cookies)
curl -X POST http://${INGRESS_IP}/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"Demo123!"}' \
  -c cookies.txt

# Now you can create todos
curl -X POST http://${INGRESS_IP}/todo/USER_ID \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"name":"Complete Wiz presentation","status":"pending"}'
