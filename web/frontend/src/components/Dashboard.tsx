import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { Server, CheckCircle, XCircle, Database, Activity, Users, ArrowRight } from 'lucide-react'
import { Button } from './ui/button'
import { Card, CardContent, CardHeader, CardTitle } from './ui/card'
import { Input } from './ui/input'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from './ui/dialog'
import axios from 'axios'

interface DashboardProps {
  setConnected: (connected: boolean) => void
}

interface Cluster {
  name: string
  host: string | null
  port: number
  nodes: { host: string; port: number }[]
  base_dn: string | null
  bind_dn: string
  readonly: boolean
  description: string
}

interface ClusterStatus {
  name: string
  connected: boolean
  passwordCached: boolean
  stats?: {
    entries: number
    groups: number
    users: number
  }
}

export default function Dashboard() {
  const navigate = useNavigate()
  const [clusters, setClusters] = useState<Cluster[]>([])
  const [clusterStatuses, setClusterStatuses] = useState<Map<string, ClusterStatus>>(new Map())
  const [showPasswordDialog, setShowPasswordDialog] = useState(false)
  const [selectedCluster, setSelectedCluster] = useState<string>('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    loadClusters()
  }, [])

  const loadClusters = async () => {
    try {
      const res = await axios.get('/api/clusters/list')
      const clusterList = res.data.clusters || []
      setClusters(clusterList)
      
      // Check password cache for each cluster
      const statuses = new Map<string, ClusterStatus>()
      for (const cluster of clusterList) {
        const cacheRes = await axios.get(`/api/password/check/${cluster.name}`)
        statuses.set(cluster.name, {
          name: cluster.name,
          connected: false,
          passwordCached: cacheRes.data.cached
        })
      }
      setClusterStatuses(statuses)
    } catch (err) {
      console.error('Failed to load clusters', err)
    }
  }

  const handleConnect = async (clusterName: string) => {
    const status = clusterStatuses.get(clusterName)
    if (!status?.passwordCached) {
      setSelectedCluster(clusterName)
      setShowPasswordDialog(true)
    }
  }

  const connectToCluster = async (clusterName: string, pwd: string) => {
    setLoading(true)
    setError('')
    try {
      await axios.post('/api/connection/connect', {
        cluster_name: clusterName,
        bind_password: pwd
      })
      
      // Update status - password now cached
      const newStatuses = new Map(clusterStatuses)
      newStatuses.set(clusterName, {
        name: clusterName,
        connected: false,
        passwordCached: true
      })
      setClusterStatuses(newStatuses)
      setShowPasswordDialog(false)
      setPassword('')
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Connection failed')
    }
    setLoading(false)
  }

  const handlePasswordSubmit = () => {
    if (!password) {
      setError('Password required')
      return
    }
    connectToCluster(selectedCluster, password)
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-3xl font-bold text-foreground">LDAP Clusters</h2>
        <p className="text-muted-foreground">Manage multiple LDAP clusters</p>
      </div>

      {clusters.length === 0 ? (
        <Card>
          <CardContent className="p-6">
            <p className="text-muted-foreground">Loading clusters...</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4">
          {clusters.map(cluster => {
            const status = clusterStatuses.get(cluster.name)
            return (
              <Card key={cluster.name}>
                <CardHeader>
                  <CardTitle className="flex items-center justify-between">
                    <div className="flex items-center space-x-2">
                      <Database className="h-5 w-5 text-primary" />
                      <span>{cluster.name}</span>
                      {status?.passwordCached && (
                        <CheckCircle className="h-4 w-4 text-primary" />
                      )}
                    </div>
                    <div className="flex space-x-2">
                      {status?.passwordCached ? (
                        <Button 
                          onClick={() => navigate(`/cluster/${encodeURIComponent(cluster.name)}`)}
                          variant="default"
                        >
                          View Cluster <ArrowRight className="h-4 w-4 ml-1" />
                        </Button>
                      ) : (
                        <Button 
                          onClick={() => handleConnect(cluster.name)}
                          disabled={loading}
                          variant="outline"
                        >
                          Setup Password
                        </Button>
                      )}
                    </div>
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="space-y-2 text-sm">
                    <div className="flex items-center space-x-2 text-muted-foreground">
                      <Server className="h-4 w-4" />
                      <span>{cluster.host || `${cluster.nodes.length} nodes`}</span>
                      <span>:{cluster.port}</span>
                    </div>
                    {cluster.description && (
                      <p className="text-muted-foreground">{cluster.description}</p>
                    )}
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      <Dialog open={showPasswordDialog} onOpenChange={setShowPasswordDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Setup Password for {selectedCluster}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium mb-2">Password</label>
              <Input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Enter bind password"
                onKeyPress={(e) => e.key === 'Enter' && handlePasswordSubmit()}
              />
              <p className="text-xs text-muted-foreground mt-1">
                Password will be cached securely for future connections
              </p>
            </div>
            {error && (
              <div className="flex items-center space-x-2 text-destructive text-sm">
                <XCircle className="h-4 w-4" />
                <span>{error}</span>
              </div>
            )}
            <Button onClick={handlePasswordSubmit} disabled={loading} className="w-full">
              {loading ? 'Saving...' : 'Save Password'}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
