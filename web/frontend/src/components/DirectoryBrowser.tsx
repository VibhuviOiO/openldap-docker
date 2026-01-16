import { useState } from 'react'
import { Search, Plus, Edit, Trash2 } from 'lucide-react'
import { Button } from './ui/button'
import { Card, CardContent, CardHeader, CardTitle } from './ui/card'

interface LDAPEntry {
  dn: string
  attributes: Record<string, any>
}

export default function DirectoryBrowser() {
  const [entries] = useState<LDAPEntry[]>([])
  const [filter, setFilter] = useState('(objectClass=*)')

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-3xl font-bold text-foreground">Directory Browser</h2>
          <p className="text-muted-foreground">Browse and manage LDAP entries</p>
        </div>
        <Button className="flex items-center space-x-2">
          <Plus className="h-4 w-4" />
          <span>New Entry</span>
        </Button>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center space-x-2">
            <Search className="h-5 w-5 text-primary" />
            <span>Search</span>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex space-x-2">
            <input
              type="text"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              placeholder="LDAP filter (e.g., (uid=john))"
              className="flex-1 px-3 py-2 border rounded-md bg-background"
            />
            <Button>Search</Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Entries</CardTitle>
        </CardHeader>
        <CardContent>
          {entries.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              <Search className="h-12 w-12 mx-auto mb-4 opacity-50" />
              <p>No entries found. Connect to LDAP and search.</p>
            </div>
          ) : (
            <div className="space-y-2">
              {entries.map((entry, i) => (
                <div key={i} className="flex items-center justify-between p-3 border rounded-md hover:bg-accent">
                  <div>
                    <p className="font-medium">{entry.dn}</p>
                    <p className="text-sm text-muted-foreground">
                      {Object.keys(entry.attributes).length} attributes
                    </p>
                  </div>
                  <div className="flex space-x-2">
                    <Button variant="ghost" size="icon">
                      <Edit className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="icon">
                      <Trash2 className="h-4 w-4 text-destructive" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
