import { Activity, Server, Database } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from './ui/card'

export default function Monitoring() {
  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-3xl font-bold text-foreground">Monitoring</h2>
        <p className="text-muted-foreground">Real-time cluster metrics</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center space-x-2 text-lg">
              <Server className="h-5 w-5 text-primary" />
              <span>Nodes</span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold text-primary">3</div>
            <p className="text-sm text-muted-foreground">Active nodes</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center space-x-2 text-lg">
              <Database className="h-5 w-5 text-primary" />
              <span>Entries</span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold text-primary">10,523</div>
            <p className="text-sm text-muted-foreground">Total entries</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center space-x-2 text-lg">
              <Activity className="h-5 w-5 text-primary" />
              <span>Status</span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold text-primary">Healthy</div>
            <p className="text-sm text-muted-foreground">All nodes in sync</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Cluster Nodes</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {['ldap-node1', 'ldap-node2', 'ldap-node3'].map((node, i) => (
              <div key={i} className="flex items-center justify-between p-4 border rounded-md">
                <div className="flex items-center space-x-3">
                  <div className="h-3 w-3 rounded-full bg-primary" />
                  <div>
                    <p className="font-medium">{node}</p>
                    <p className="text-sm text-muted-foreground">Port: {389 + i}</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="text-sm font-medium text-primary">Healthy</p>
                  <p className="text-xs text-muted-foreground">15ms response</p>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
