import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { ArrowLeft, Search } from 'lucide-react'
import { Button } from './ui/button'
import { Card, CardContent, CardHeader, CardTitle } from './ui/card'
import { Input } from './ui/input'
import DirectoryStats from './DirectoryStats'
import DirectoryTable from './DirectoryTable'
import MonitoringView from './MonitoringView'
import ActivityLogView from './ActivityLogView'
import axios from 'axios'

export default function ClusterDetails() {
  const { clusterName } = useParams<{ clusterName: string }>()
  const navigate = useNavigate()
  const [activeTab, setActiveTab] = useState<'directory' | 'monitoring' | 'activity'>('directory')
  const [directoryView, setDirectoryView] = useState<'users' | 'groups' | 'ous' | 'all'>('users')
  const [entries, setEntries] = useState<any[]>([])
  const [monitoring, setMonitoring] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  const [page, setPage] = useState(1)
  const [pageSize] = useState(10)
  const [totalEntries, setTotalEntries] = useState(0)
  const [hasMore, setHasMore] = useState(false)

  useEffect(() => {
    loadMonitoring()
    if (activeTab === 'directory') {
      loadClusterData()
    }
  }, [clusterName, activeTab, directoryView, page, searchQuery])

  const loadClusterData = async () => {
    setLoading(true)
    try {
      const filterType = directoryView === 'all' ? '' : directoryView
      const res = await axios.get(`/api/entries/search`, {
        params: {
          cluster: clusterName,
          page,
          page_size: pageSize,
          filter_type: filterType,
          search: searchQuery || undefined
        }
      })
      
      setEntries(res.data.entries || [])
      setTotalEntries(res.data.total || 0)
      setHasMore(res.data.has_more || false)
    } catch (err) {
      console.error('Failed to load cluster data', err)
    }
    setLoading(false)
  }

  const handleSearch = (value: string) => {
    setSearchQuery(value)
    setPage(1)
  }

  const handleViewChange = (view: 'users' | 'groups' | 'ous' | 'all') => {
    setDirectoryView(view)
    setPage(1)
  }

  const getFilteredEntries = () => entries

  const loadMonitoring = async () => {
    setLoading(true)
    try {
      const res = await axios.get(`/api/monitoring/health?cluster=${clusterName}`)
      setMonitoring(res.data)
    } catch (err) {
      console.error('Failed to load monitoring data', err)
    }
    setLoading(false)
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-4">
          <Button variant="ghost" onClick={() => navigate('/')}>
            <ArrowLeft className="h-4 w-4 mr-2" />
            Back
          </Button>
          <div>
            <h2 className="text-3xl font-bold text-foreground">{decodeURIComponent(clusterName || '')}</h2>
            <div className="flex items-center space-x-2">
              <p className="text-muted-foreground">Cluster Details</p>
              {monitoring && (
                <span className={`text-sm px-2 py-1 rounded ${
                  monitoring.status === 'healthy' 
                    ? 'bg-primary/10 text-primary' 
                    : 'bg-destructive/10 text-destructive'
                }`}>
                  {monitoring.status === 'healthy' ? '● Healthy' : '● Unhealthy'}
                </span>
              )}
            </div>
          </div>
        </div>
      </div>

      <div className="flex space-x-2 border-b">
        <button
          onClick={() => setActiveTab('directory')}
          className={`px-4 py-2 font-medium ${
            activeTab === 'directory'
              ? 'text-primary border-b-2 border-primary'
              : 'text-muted-foreground hover:text-foreground'
          }`}
        >
          Directory
        </button>
        <button
          onClick={() => setActiveTab('monitoring')}
          className={`px-4 py-2 font-medium ${
            activeTab === 'monitoring'
              ? 'text-primary border-b-2 border-primary'
              : 'text-muted-foreground hover:text-foreground'
          }`}
        >
          Monitoring
        </button>
        <button
          onClick={() => setActiveTab('activity')}
          className={`px-4 py-2 font-medium ${
            activeTab === 'activity'
              ? 'text-primary border-b-2 border-primary'
              : 'text-muted-foreground hover:text-foreground'
          }`}
        >
          Activity Log
        </button>
      </div>

      {activeTab === 'directory' ? (
        <>
          <DirectoryStats clusterName={clusterName || ''} />

          <div className="flex space-x-2 border-b">
            <button
              onClick={() => handleViewChange('users')}
              className={`px-4 py-2 text-sm font-medium ${
                directoryView === 'users'
                  ? 'text-primary border-b-2 border-primary'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              Users
            </button>
            <button
              onClick={() => handleViewChange('groups')}
              className={`px-4 py-2 text-sm font-medium ${
                directoryView === 'groups'
                  ? 'text-primary border-b-2 border-primary'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              Groups
            </button>
            <button
              onClick={() => handleViewChange('ous')}
              className={`px-4 py-2 text-sm font-medium ${
                directoryView === 'ous'
                  ? 'text-primary border-b-2 border-primary'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              Organizational Units
            </button>
            <button
              onClick={() => handleViewChange('all')}
              className={`px-4 py-2 text-sm font-medium ${
                directoryView === 'all'
                  ? 'text-primary border-b-2 border-primary'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              All Entries
            </button>
          </div>

          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <CardTitle>
                  {directoryView === 'users' && 'Users'}
                  {directoryView === 'groups' && 'Groups'}
                  {directoryView === 'ous' && 'Organizational Units'}
                  {directoryView === 'all' && 'All Directory Entries'}
                </CardTitle>
                <div className="relative w-80">
                  <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                  <Input
                    type="text"
                    placeholder="Search by username, name, email..."
                    value={searchQuery}
                    onChange={(e) => handleSearch(e.target.value)}
                    className="pl-10"
                  />
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <DirectoryTable
                entries={getFilteredEntries()}
                directoryView={directoryView}
                loading={loading}
                page={page}
                pageSize={pageSize}
                totalEntries={totalEntries}
                hasMore={hasMore}
                onPageChange={setPage}
              />
            </CardContent>
          </Card>
        </>
      ) : activeTab === 'monitoring' ? (
        <MonitoringView monitoring={monitoring} loading={loading} />
      ) : (
        <ActivityLogView />
      )}
    </div>
  )
}
