import { useState } from 'react'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { Database } from 'lucide-react'
import Dashboard from './components/Dashboard'
import ClusterDetails from './components/ClusterDetails'

function App() {
  return (
    <BrowserRouter>
      <div className="min-h-screen bg-background">
        <header className="border-b bg-card">
          <div className="container mx-auto px-4 py-4">
            <div className="flex items-center space-x-2">
              <Database className="h-8 w-8 text-primary" />
              <h1 className="text-2xl font-bold text-primary">LDAP Manager</h1>
            </div>
          </div>
        </header>

        <main className="container mx-auto px-4 py-8">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/cluster/:clusterName" element={<ClusterDetails />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  )
}

export default App
