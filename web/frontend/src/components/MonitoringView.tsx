import { Card, CardContent, CardHeader, CardTitle } from './ui/card'

interface MonitoringViewProps {
  monitoring: any
  loading: boolean
}

export default function MonitoringView({ monitoring, loading }: MonitoringViewProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Cluster Health Monitoring</CardTitle>
      </CardHeader>
      <CardContent>
        {loading ? (
          <p className="text-muted-foreground">Loading monitoring data...</p>
        ) : monitoring ? (
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Status</p>
                <p className="text-lg font-bold">{monitoring.status || 'Unknown'}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Response Time</p>
                <p className="text-lg font-bold">{monitoring.responseTime || 'N/A'}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Connections</p>
                <p className="text-lg font-bold">{monitoring.connections || 0}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Operations</p>
                <p className="text-lg font-bold">{monitoring.operations || 0}</p>
              </div>
            </div>
          </div>
        ) : (
          <p className="text-muted-foreground">No monitoring data available</p>
        )}
      </CardContent>
    </Card>
  )
}
