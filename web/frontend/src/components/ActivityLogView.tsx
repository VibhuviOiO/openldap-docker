import { Activity } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from './ui/card'

export default function ActivityLogView() {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <Activity className="h-5 w-5 text-primary" />
          <span>Activity Log</span>
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          <div className="bg-muted/50 p-4 rounded-lg border">
            <h3 className="font-semibold mb-2">📝 Activity Logs Location</h3>
            <p className="text-sm text-muted-foreground mb-3">
              Activity logs are stored on the host filesystem and must be accessed via command line.
            </p>
            
            <div className="space-y-3">
              <div>
                <p className="text-sm font-medium mb-1">View live logs:</p>
                <code className="text-xs bg-background px-2 py-1 rounded block">
                  tail -f ./logs/slapd.log
                </code>
              </div>
              
              <div>
                <p className="text-sm font-medium mb-1">Search for user activity:</p>
                <code className="text-xs bg-background px-2 py-1 rounded block">
                  grep "uid=username" ./logs/slapd.log
                </code>
              </div>
              
              <div>
                <p className="text-sm font-medium mb-1">Find failed logins:</p>
                <code className="text-xs bg-background px-2 py-1 rounded block">
                  grep "err=49" ./logs/slapd.log
                </code>
              </div>
              
              <div>
                <p className="text-sm font-medium mb-1">View archived logs:</p>
                <code className="text-xs bg-background px-2 py-1 rounded block">
                  zcat ./logs/slapd.log-2026-01-16.gz | less
                </code>
              </div>
            </div>
          </div>
          
          <div className="bg-primary/5 p-4 rounded-lg border border-primary/20">
            <h3 className="font-semibold mb-2 text-primary">📚 Full Documentation</h3>
            <p className="text-sm text-muted-foreground mb-2">
              For complete log management instructions, see:
            </p>
            <code className="text-xs bg-background px-2 py-1 rounded block">
              docs/ACTIVITY_LOGS.md
            </code>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
