import { useState, useEffect, useCallback } from 'react'

export function useWorkspaceMembers() {
  const [members, setMembers] = useState([])
  const [isLoading, setIsLoading] = useState(false)

  const fetchOrgMembers = useCallback(async () => {
    // Get current workspace from window.Auth
    const userData = typeof window !== 'undefined' && window.Auth?.user?.() || {}
    const currentOrg = userData.currentWorkspace

    if (!currentOrg?.id) {
      setMembers([])
      return
    }

    setIsLoading(true)

    try {
      // Fetch members from current workspace (excluding self)
      const response = await fetch(`/api/v1/mentionables?query=&model=Member`, {
        headers: {
          'Accept': 'application/json'
        }
      })

      if (!response.ok) {
        throw new Error('Failed to fetch workspace members')
      }

      const data = await response.json()

      // Handle both array and {results: []} format
      const resultsArray = Array.isArray(data) ? data : (data.results || [])

      if (!Array.isArray(resultsArray)) {
        console.error('[useWorkspaceMembers] No valid results array:', data)
        setMembers([])
        return
      }

      // Transform to OrgMember format
      const orgMembers = resultsArray
        .filter((m) => m.model === 'Member')
        .map((m) => ({
          memberId: m.id,
          userName: m.label.split(' | ')[0] || m.label,
          orgName: currentOrg.name,
          orgType: currentOrg.personal ? 'Personal' : 'Team'
        }))

      setMembers(orgMembers)
    } catch (err) {
      console.error('[useWorkspaceMembers] Fetch error:', err)
      setMembers([])
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchOrgMembers()
  }, [fetchOrgMembers])

  return {
    members,
    isLoading
  }
}

export default useWorkspaceMembers
