import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Button } from './ui/button'

interface DirectoryTableProps {
  entries: any[]
  directoryView: 'users' | 'groups' | 'ous' | 'all'
  loading: boolean
  page: number
  pageSize: number
  totalEntries: number
  hasMore: boolean
  onPageChange: (page: number) => void
}

export default function DirectoryTable({
  entries, directoryView, loading, page, pageSize, totalEntries, hasMore, onPageChange
}: DirectoryTableProps) {
  if (loading) return <p className="text-muted-foreground">Loading entries...</p>
  if (entries.length === 0) return <p className="text-muted-foreground">No entries found</p>

  return (
    <>
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr className="border-b">
              {directoryView === 'users' && (
                <>
                  <th className="text-left p-3 font-medium text-sm">Username</th>
                  <th className="text-left p-3 font-medium text-sm">Full Name</th>
                  <th className="text-left p-3 font-medium text-sm">Email</th>
                  <th className="text-left p-3 font-medium text-sm">Details</th>
                  <th className="text-left p-3 font-medium text-sm">Object Class</th>
                </>
              )}
              {directoryView === 'groups' && (
                <>
                  <th className="text-left p-3 font-medium text-sm">Group Name</th>
                  <th className="text-left p-3 font-medium text-sm">Description</th>
                  <th className="text-left p-3 font-medium text-sm">Members</th>
                  <th className="text-left p-3 font-medium text-sm">DN</th>
                </>
              )}
              {directoryView === 'ous' && (
                <>
                  <th className="text-left p-3 font-medium text-sm">OU Name</th>
                  <th className="text-left p-3 font-medium text-sm">Description</th>
                  <th className="text-left p-3 font-medium text-sm">DN</th>
                </>
              )}
              {directoryView === 'all' && (
                <>
                  <th className="text-left p-3 font-medium text-sm">DN</th>
                  <th className="text-left p-3 font-medium text-sm">Object Class</th>
                  <th className="text-left p-3 font-medium text-sm">Attributes</th>
                </>
              )}
            </tr>
          </thead>
          <tbody>
            {entries.map((entry, idx) => (
              <tr key={idx} className="border-b hover:bg-accent">
                {directoryView === 'users' && (
                  <>
                    <td className="p-3 text-sm font-medium">{entry.uid || entry.cn || '-'}</td>
                    <td className="p-3 text-sm">{entry.cn || '-'}</td>
                    <td className="p-3 text-sm text-muted-foreground">{entry.mail || '-'}</td>
                    <td className="p-3 text-sm">
                      {(() => {
                        if (entry.role || entry.kingdom) {
                          return (
                            <div>
                              <div className="font-medium">{entry.role || '-'}</div>
                              {entry.kingdom && <div className="text-xs text-muted-foreground">{entry.kingdom}</div>}
                            </div>
                          )
                        }
                        const detail = entry.title || entry.departmentNumber || entry.ou || 
                                      entry.organizationalUnit || entry.description
                        const subDetail = entry.title ? (entry.departmentNumber || entry.ou) : null
                        
                        return detail ? (
                          <div>
                            <div className="font-medium">{detail}</div>
                            {subDetail && <div className="text-xs text-muted-foreground">{subDetail}</div>}
                          </div>
                        ) : '-'
                      })()}
                    </td>
                    <td className="p-3 text-sm">
                      {(() => {
                        const objectClasses = Array.isArray(entry.objectClass) 
                          ? entry.objectClass 
                          : (entry.objectClass ? [entry.objectClass] : [])
                        
                        const customClasses = objectClasses.filter((oc: string) => 
                          !['top', 'person', 'organizationalPerson', 'inetOrgPerson', 
                           'posixAccount', 'shadowAccount', 'account'].includes(oc)
                        )
                        
                        if (customClasses.length > 0) {
                          return (
                            <div className="space-y-1">
                              <span className="px-2 py-1 bg-primary/10 text-primary rounded text-xs block w-fit">
                                {customClasses[0]}
                              </span>
                              {entry.isAdmin === 'TRUE' && (
                                <span className="px-2 py-1 bg-amber-500/10 text-amber-600 rounded text-xs block w-fit">
                                  Admin
                                </span>
                              )}
                            </div>
                          )
                        }
                        
                        if (objectClasses.includes('account') && !objectClasses.includes('inetOrgPerson')) {
                          return (
                            <span className="px-2 py-1 bg-blue-500/10 text-blue-600 rounded text-xs">
                              Legacy Unix
                            </span>
                          )
                        }
                        
                        return (
                          <span className="px-2 py-1 bg-muted text-muted-foreground rounded text-xs">
                            Standard
                          </span>
                        )
                      })()}
                    </td>
                  </>
                )}
                {directoryView === 'groups' && (
                  <>
                    <td className="p-3 text-sm font-medium">{entry.cn || '-'}</td>
                    <td className="p-3 text-sm">{entry.description || '-'}</td>
                    <td className="p-3 text-sm text-muted-foreground">
                      {(() => {
                        const members = entry.member || entry.uniqueMember || []
                        const count = Array.isArray(members) ? members.length : (members ? 1 : 0)
                        return `${count} member${count !== 1 ? 's' : ''}`
                      })()}
                    </td>
                    <td className="p-3 text-xs font-mono text-muted-foreground">{entry.dn}</td>
                  </>
                )}
                {directoryView === 'ous' && (
                  <>
                    <td className="p-3 text-sm font-medium">{entry.ou || entry.o || '-'}</td>
                    <td className="p-3 text-sm">{entry.description || '-'}</td>
                    <td className="p-3 text-xs font-mono text-muted-foreground">{entry.dn}</td>
                  </>
                )}
                {directoryView === 'all' && (
                  <>
                    <td className="p-3 text-sm font-mono">{entry.dn}</td>
                    <td className="p-3 text-sm">
                      <span className="px-2 py-1 bg-primary/10 text-primary rounded text-xs">
                        {entry.objectClass?.[entry.objectClass.length - 1] || 'Unknown'}
                      </span>
                    </td>
                    <td className="p-3 text-sm text-muted-foreground">
                      {Object.keys(entry)
                        .filter(k => k !== 'dn' && k !== 'objectClass')
                        .slice(0, 3)
                        .map(k => `${k}: ${Array.isArray(entry[k]) ? entry[k][0] : entry[k]}`)
                        .join(', ')}
                    </td>
                  </>
                )}
              </tr>
            ))}
          </tbody>
        </table>
        
        <div className="flex items-center justify-between pt-4 border-t">
          <p className="text-sm text-muted-foreground">
            Showing {((page - 1) * pageSize) + 1} to {Math.min(page * pageSize, totalEntries)} of {totalEntries} entries
          </p>
          <div className="flex items-center space-x-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => onPageChange(page - 1)}
              disabled={page === 1}
            >
              <ChevronLeft className="h-4 w-4" />
              Previous
            </Button>
            <span className="text-sm text-muted-foreground">Page {page}</span>
            <Button
              variant="outline"
              size="sm"
              onClick={() => onPageChange(page + 1)}
              disabled={!hasMore && entries.length < pageSize}
            >
              Next
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
    </>
  )
}
